#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf_gz="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"

    # FastQC
    fastqc -o "$results" "data/raw/${sample}_1.${sample//-/_}2.fq.gz" data/raw/${sample}_2.${sample//-/_}2.fq.gz

    # BWA index
    bwa index chrM.fa

    # BWA alignment
    bwa mem -t 4 chrM.fa "data/raw/${sample}_1.${sample//-/_}2.fq.gz" "data/raw/${sample}_2.${sample//-/_}2.fq.gz" > "$bam"

    samtools view -b -f 0 $bam | samtools sort -o "$bam.sorted" -

    samtools index "$bam.sorted"
    mv "$bam.sorted" "$bam"
    samtools index "$bam"

    # Bcftools call
    bcftools view -Oz "$bam" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    mv "$tbi" "$results/${sample}.vcf.gz.tbi"

    # SnpSift filter (optional, but required for AF)
    snpsift -r chrM.16569.fa $bam > "${sample}_filtered.bam"
    samtools view -b -f 0 "${sample}_filtered.bam" | bcftools call -Oz > "${sample}.vcf.gz"

    # Collapse table
    if [ ! -s "$results/collapsed.tsv" ]; then
        echo "sample\tchrom\tpos\tref\talt\taf" > "$results/collapsed.tsv"
    fi

    samtools view -h $bam | bcftools call -Oz -o "${sample}_vcf.merged.vcf.gz" &
done

wait
samtools merge -tbi -o results/merged.vcf.gz $results/*.vcf.gz
tabix -p vcf results/merged.vcf.gz

# Extract AF and collapse to TSV
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    af=$(bcftools query -h $results/${sample}.vcf.gz | awk 'NR==2 {print $9}' | cut -d/ -f2)
    if [ "$af" != "NA" ]; then
        echo "$sample\tchrM\t$((16569))\tA\tT\t$af" >> "$results/collapsed.tsv"
    fi
done

# Cleanup temp files
rm -rf $results/*.bam $results/*.vcf.gz $results/*.vcf.merged.vcf.gz $results/*.tbi $results/*.bai $results/*.filtered.bam $results/*.sorted $results/*.index $results/*.fastqc $results/*.log

# Final merge and index
samtools merge -o results/collapsed.tsv $results/collapsed.tsv
rm "$results/collapsed.merged.vcf.gz"