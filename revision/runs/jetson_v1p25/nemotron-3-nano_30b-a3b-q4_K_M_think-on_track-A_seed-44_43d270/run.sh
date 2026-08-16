#!/usr/bin/env bash
set -euo pipefail
THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Index reference (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Process each sample
for samp in $samples; do
    # Skip if final TBI exists
    if [ -f results/${samp}.vcf.gz.tbi ]; then
        continue
    fi

    # Alignment and sorting
    bwa mem -t "$THREADS" -R "@RG\\tID:${samp}\\tSM:${samp}\\tLB:${samp}\\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${samp}_1.fq.gz data/raw/${samp}_2.fq.gz |
        samtools sort -@ "$THREADS" -o results/${samp}.bam -

    # Index BAM
    samtools index -@ "$THREADS" results/${samp}.bam

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o results/${samp}.vcf results/${samp}.bam

    # Compress VCF and index
    bgzip -c results/${samp}.vcf > results/${samp}.vcf.gz
    tabix -p vcf results/${samp}.vcf.gz
    rm results/${samp}.vcf
done

# Rebuild collapsed.tsv if any VCF is newer
if [ -f results/collapsed.tsv ]; then
    if find results -maxdepth 1 -name '*.vcf.gz' -newer results/collapsed.tsv | grep -q .; then
        need_rebuild=1
    else
        need_rebuild=0
    fi
else
    need_rebuild=1
fi

if [ "$need_rebuild" -eq 1 ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for samp in $samples; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${samp}.vcf.gz |
                awk -v sample="$samp" '{print sample"\t"$0}'
        done
    } > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0